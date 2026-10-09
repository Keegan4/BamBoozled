import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/widgets/pills.dart';
import '../../../data/providers.dart';
import '../../../domain/models/priority.dart';
import '../welcome_controller.dart';

/// Rounded search box. Filters tasks as you type.
class TaskSearchField extends ConsumerStatefulWidget {
  const TaskSearchField({super.key, this.autofocus = false});
  final bool autofocus;

  @override
  ConsumerState<TaskSearchField> createState() => _TaskSearchFieldState();
}

class _TaskSearchFieldState extends ConsumerState<TaskSearchField> {
  late final _controller = TextEditingController(text: ref.read(taskFilterProvider).query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(taskFilterProvider.select((f) => f.query), (_, q) {
      if (q != _controller.text) _controller.text = q;
    });
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      style: PandaText.body,
      textInputAction: TextInputAction.search,
      onChanged: (q) => ref.read(taskFilterProvider.notifier).setQuery(q),
      decoration: InputDecoration(
        hintText: 'Search tasks or notes…',
        fillColor: context.panda.surface,
        prefixIcon: Icon(Icons.search_rounded, color: context.panda.muted),
        suffixIcon: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    ref.read(taskFilterProvider.notifier).setQuery('');
                  },
                ),
        ),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(PandaSizes.pill))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(PandaSizes.pill)),
          borderSide: BorderSide(color: context.panda.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(PandaSizes.pill)),
          borderSide: BorderSide(color: context.panda.bambooDark, width: 2),
        ),
      ),
    );
  }
}

/// "All" plus one colour-coded chip per category. If there are more than fit, the row scrolls: it
/// has a visible scrollbar, can be dragged with a finger or the mouse, and the mouse wheel moves it.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key, this.wrap = false});

  /// Wrap onto several lines instead of scrolling sideways.
  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final selected = ref.watch(taskFilterProvider.select((f) => f.categoryIds));
    final notifier = ref.read(taskFilterProvider.notifier);
    final chips = [
      OptionPill(
        label: 'All',
        style: OptionPillStyle.ink,
        selected: selected.isEmpty,
        onTap: notifier.showAllCategories,
      ),
      for (final c in categories)
        OptionPill(
          label: c.name,
          dotColor: c.color,
          style: OptionPillStyle.ink,
          selected: selected.contains(c.id),
          onTap: () => notifier.toggleCategory(c.id),
        ),
    ];
    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return _HorizontalScroller(
      child: Row(
        children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
      ),
    );
  }
}

/// A sideways-scrolling row with an always-visible scrollbar underneath.
class _HorizontalScroller extends StatefulWidget {
  const _HorizontalScroller({required this.child});
  final Widget child;

  @override
  State<_HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<_HorizontalScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A mouse wheel only scrolls up and down, so turn it into sideways movement for this row.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(0.0, position.maxScrollExtent);
    if (target == _controller.offset) return; // at the end: let the page scroll instead
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => _controller.jumpTo(target));
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onPointerSignal,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        scrollbars: false,
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 14),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// "Showing only: General · Done" with a button to clear it. Without this, hidden tasks look like
/// missing tasks.
class ActiveFilterBanner extends ConsumerWidget {
  const ActiveFilterBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    if (!filter.hasAnyFilter) return const SizedBox.shrink();
    final parts = filter.describe(ref.watch(categoryMapProvider));
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Container(
        key: const ValueKey('active-filters'),
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: context.panda.bambooTint,
          borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_alt_rounded, size: 18, color: context.panda.bambooDark),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Showing only: ${parts.join(' · ')}',
                  style: PandaText.captionStrong.copyWith(color: context.panda.bambooDark),
                ),
              ),
            ),
            TextButton(onPressed: ref.read(taskFilterProvider.notifier).reset, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

const _priorityItems = <Priority?, String>{
  null: 'Any',
  Priority.low: 'Low',
  Priority.medium: 'Medium',
  Priority.high: 'High',
  Priority.urgent: 'Urgent',
};

/// Desktop/tablet filter row: category chips, then priority and status menus.
class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final notifier = ref.read(taskFilterProvider.notifier);
    final menus = [
      Icon(Icons.filter_alt_outlined, color: context.panda.muted, size: 20),
      DropdownPill<Priority?>(
        label: 'Priority',
        value: filter.priority,
        items: _priorityItems,
        onSelected: notifier.setPriority,
      ),
      DropdownPill<StatusFilter>(
        label: 'Status',
        value: filter.status,
        items: {for (final s in StatusFilter.values) s: s.label},
        onSelected: notifier.setStatus,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Chips and menus share one line when there's room; otherwise the menus go underneath.
        if (constraints.maxWidth < 1000) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CategoryChips(),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: menus),
            ],
          );
        }
        return Row(
          children: [
            const Expanded(child: CategoryChips()),
            for (final m in menus) Padding(padding: const EdgeInsets.only(left: 8), child: m),
          ],
        );
      },
    );
  }
}

/// Phone filter row: a Filter button (opens a sheet) and the category chips.
class CompactFilterBar extends ConsumerWidget {
  const CompactFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(taskFilterProvider.select((f) => f.activeCount));
    return Row(
      children: [
        OptionPill(
          label: active == 0 ? 'Filter' : 'Filter ($active)',
          icon: Icons.filter_alt_outlined,
          selected: false,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: context.panda.surface,
            builder: (_) => const FilterSheet(),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: CategoryChips()),
      ],
    );
  }
}

/// All filters in one place, for phones.
class FilterSheet extends ConsumerWidget {
  const FilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final notifier = ref.read(taskFilterProvider.notifier);
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PandaText.heading),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Filter tasks', style: PandaText.title),
          const SizedBox(height: 16),
          section('Category', const CategoryChips(wrap: true)),
          section(
            'Priority',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _priorityItems.entries)
                  OptionPill(
                    label: e.value,
                    selected: filter.priority == e.key,
                    onTap: () => notifier.setPriority(e.key),
                  ),
              ],
            ),
          ),
          section(
            'Status',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in StatusFilter.values)
                  OptionPill(label: s.label, selected: filter.status == s, onTap: () => notifier.setStatus(s)),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: notifier.reset, child: const Text('Clear filters')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Show tasks')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
