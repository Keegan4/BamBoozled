import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/pills.dart';
import '../../data/canvas/canvas_feed.dart';
import '../../data/providers.dart';

/// Settings → Canvas: connect a Canvas calendar feed so assignments show up as tasks.
class CanvasCard extends ConsumerStatefulWidget {
  const CanvasCard({super.key});

  @override
  ConsumerState<CanvasCard> createState() => _CanvasCardState();
}

class _CanvasCardState extends ConsumerState<CanvasCard> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(canvasServiceProvider).refresh(force: true);
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (result != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_changes(result.added, result.updated, result.removed))));
    }
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Canvas?', style: PandaText.title),
        content: const Text(
          'The assignments that came from Canvas will be removed from BamBoozled. '
          'Nothing changes in Canvas itself, and you can connect again at any time.',
          style: PandaText.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep connected')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.panda.overdue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(canvasServiceProvider).disconnect();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Canvas disconnected')));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(canvasStatusProvider).value;
    final now = ref.watch(clockProvider);
    final List<Widget> content;
    if (status == null || !status.connected) {
      content = [
        Text(
          'See your Canvas assignments in BamBoozled, with their due dates, sorted into a category for each course.',
          style: PandaText.body.copyWith(color: context.panda.muted),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const ConnectCanvasDialog()),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect Canvas'),
          ),
        ),
      ];
    } else {
      final synced = status.lastSyncedAt;
      final when = synced == null
          ? 'Not updated yet'
          : 'Updated ${dateOnly(synced) == dateOnly(now) ? 'at ${formatTime(synced)}' : formatShortDate(synced, now)}';
      content = [
        Text('Connected to ${status.host ?? 'Canvas'}', style: PandaText.bodyStrong),
        const SizedBox(height: 4),
        Text(
          '$when · ${status.itemCount} ${status.itemCount == 1 ? 'assignment' : 'assignments'} · checks every hour',
          style: PandaText.body.copyWith(color: context.panda.muted),
        ),
        if (status.lastError != null) ...[
          const SizedBox(height: 8),
          Text(status.lastError!, style: PandaText.body.copyWith(color: context.panda.overdue)),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_refreshing ? 'Updating…' : 'Update now'),
            ),
            OutlinedButton(onPressed: _refreshing ? null : _disconnect, child: const Text('Disconnect')),
          ],
        ),
      ];
    }
    return PandaCard(
      key: const ValueKey('canvas-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Canvas', style: PandaText.title),
          const SizedBox(height: 8),
          ...content,
        ],
      ),
    );
  }
}

String _changes(int added, int updated, int removed) {
  final parts = [if (added > 0) '$added new', if (updated > 0) '$updated changed', if (removed > 0) '$removed removed'];
  return parts.isEmpty ? 'Canvas is up to date' : 'Canvas updated: ${parts.join(', ')}';
}

/// Asks for the Calendar Feed link, checks it and imports the assignments.
class ConnectCanvasDialog extends ConsumerStatefulWidget {
  const ConnectCanvasDialog({super.key});

  @override
  ConsumerState<ConnectCanvasDialog> createState() => _ConnectCanvasDialogState();
}

class _ConnectCanvasDialogState extends ConsumerState<ConnectCanvasDialog> {
  final _link = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(canvasServiceProvider).connect(_link.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.total == 0
                  ? 'Connected. Canvas has no assignments to show yet.'
                  : 'Connected! Found ${result.total} ${result.total == 1 ? 'assignment' : 'assignments'}.',
            ),
          ),
        );
    } on CanvasFeedException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect Canvas', style: PandaText.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('1. In Canvas, open Calendar.', style: PandaText.body),
            const SizedBox(height: 4),
            const Text('2. Choose Calendar Feed (bottom right) and copy the link.', style: PandaText.body),
            const SizedBox(height: 4),
            const Text('3. Paste it here.', style: PandaText.body),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://canvas…/feeds/calendars/….ics'),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 8),
            Text(
              ref.watch(canvasNeedsProxyProvider)
                  ? 'Keep this link private: anyone who has it can see your Canvas calendar. '
                        'It stays in this browser; your own sync server uses it to fetch the calendar.'
                  : 'Keep this link private: anyone who has it can see your Canvas calendar. '
                        'It stays on this device and is not synced.',
              style: PandaText.caption.copyWith(color: context.panda.muted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: PandaText.caption.copyWith(color: context.panda.overdue)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? 'Checking…' : 'Connect')),
    ],
  );
}
