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
        fillColor: PandaColors.surface,
        prefixIcon: const Icon(Icons.search_rounded, color: PandaColors.muted),
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
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(PandaSizes.pill)),
          borderSide: BorderSide(color: PandaColors.line, width: 1.5),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(PandaSizes.pill)),
          borderSide: BorderSide(color: PandaColors.bambooDark, width: 2),
        ),
      ),
    );
  }
}

/// "All" plus one colour-coded chip per category.
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
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
    return Row(
      children: [
        const Expanded(child: CategoryChips()),
        const SizedBox(width: 8),
        const Icon(Icons.filter_alt_outlined, color: PandaColors.muted, size: 20),
        const SizedBox(width: 8),
        DropdownPill<Priority?>(
          label: 'Priority',
          value: filter.priority,
          items: _priorityItems,
          onSelected: notifier.setPriority,
        ),
        const SizedBox(width: 8),
        DropdownPill<StatusFilter>(
          label: 'Status',
          value: filter.status,
          items: {for (final s in StatusFilter.values) s: s.label},
          onSelected: notifier.setStatus,
        ),
      ],
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
            backgroundColor: PandaColors.surface,
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
