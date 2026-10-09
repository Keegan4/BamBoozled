import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/pills.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_service.dart';
import '../auth/sign_in_dialog.dart';
import 'canvas_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = Breakpoints.isPhone(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Text('Settings', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_NameCard(), SizedBox(height: 16), _SyncCard(), SizedBox(height: 16), CanvasCard()],
          ),
        ),
      ],
    );
  }
}

class _NameCard extends ConsumerStatefulWidget {
  const _NameCard();

  @override
  ConsumerState<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends ConsumerState<_NameCard> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(databaseProvider)
        .setSetting(displayNameKey, _controller.text.trim().isEmpty ? null : _controller.text.trim());
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name saved')));
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(displayNameProvider);
    if (!_loaded && name.hasValue) {
      _controller.text = name.value ?? '';
      _loaded = true;
    }
    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your name', style: PandaText.title),
          const SizedBox(height: 4),
          Text(
            'Shown in the greeting, e.g. “Good morning, Ms Tan”.',
            style: PandaText.caption.copyWith(color: PandaColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 40,
                  style: PandaText.body,
                  decoration: const InputDecoration(hintText: 'e.g. Ms Tan', counterText: ''),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final user = ref.watch(currentUserProvider).value;
    final status = ref.watch(syncStatusProvider).value;
    final sync = ref.watch(syncServiceProvider);

    final List<Widget> content;
    if (auth == null) {
      content = [
        Text(
          'This copy of BamBoozled keeps your tasks on this device only. '
          'To use the same tasks on your phone and computer, the app needs to be built with a sync server '
          '(see the README).',
          style: PandaText.body.copyWith(color: PandaColors.muted),
        ),
      ];
    } else if (user == null) {
      content = [
        Text(
          'Sign in with your email to see the same tasks on your phone and your computer.',
          style: PandaText.body.copyWith(color: PandaColors.muted),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const SignInDialog()),
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Sign in to sync'),
          ),
        ),
      ];
    } else {
      final last = status?.lastSyncedAt;
      final line = switch (status?.phase) {
        SyncPhase.syncing => 'Syncing…',
        SyncPhase.error => status?.message ?? 'Couldn’t sync — will retry',
        _ => last == null ? 'Waiting to sync' : 'Last synced at ${formatTime(last)}',
      };
      content = [
        Text('Signed in as ${user.email ?? 'your account'}', style: PandaText.bodyStrong),
        const SizedBox(height: 4),
        Text(
          line,
          style: PandaText.body.copyWith(
            color: status?.phase == SyncPhase.error ? PandaColors.overdue : PandaColors.muted,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: sync?.syncNow,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
            OutlinedButton(onPressed: auth.signOut, child: const Text('Sign out')),
          ],
        ),
      ];
    }

    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sync between devices', style: PandaText.title),
          const SizedBox(height: 8),
          ...content,
        ],
      ),
    );
  }
}
