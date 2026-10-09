import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/leaf_icon.dart';
import '../../core/widgets/pills.dart';
import '../../data/providers.dart';
import '../../data/repositories/task_repository.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import '../welcome/welcome_controller.dart';

/// Opens the add/edit task form: a dialog on wide screens, a bottom sheet on phones.
Future<void> showTaskEditor(BuildContext context, {Task? task, DateTime? initialDay}) {
  final editor = TaskEditor(task: task, initialDay: initialDay);
  if (Breakpoints.isPhone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PandaColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: editor,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: PandaColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: editor,
      ),
    ),
  );
}

/// The task form, laid out as recommended in docs/task-format.md.
class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, this.task, this.initialDay});

  /// The task being edited, or null to add a new one.
  final Task? task;

  /// Pre-selected due day for a new task (e.g. the day picked on the calendar).
  final DateTime? initialDay;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _dueDay;
  TimeOfDay? _time;
  late Priority _priority;
  late String _categoryId;
  int? _estimate;
  late Repeat _repeat;
  bool _showErrors = false;
  bool _saving = false;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final today = dateOnly(ref.read(clockProvider));
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _dueDay = dateOnly(t?.dueAt ?? widget.initialDay ?? today);
    _time = t != null && hasSpecificTime(t.dueAt) ? TimeOfDay.fromDateTime(t.dueAt) : null;
    _priority = t?.priority ?? Priority.medium;
    _categoryId = t?.categoryId ?? defaultCategoryId;
    _estimate = t?.estimateMinutes;
    _repeat = t?.repeat ?? Repeat.none;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _dueAt => _time == null
      ? endOfDay(_dueDay)
      : DateTime(_dueDay.year, _dueDay.month, _dueDay.day, _time!.hour, _time!.minute);

  Future<void> _save() async {
    if (_saving) return; // a double click or a held Enter key must not save twice
    if (_title.text.trim().isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(taskRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final filter = ref.read(taskFilterProvider);
    final filters = ref.read(taskFilterProvider.notifier);
    final categories = ref.read(categoryMapProvider);
    final now = ref.read(clockProvider);

    final Task saved;
    if (_editing) {
      // Start from the stored task, not the copy this form opened with, so that anything that changed
      // meanwhile (finished, or edited on another device) isn't overwritten by stale values.
      final current = await repo.getTask(widget.task!.id) ?? widget.task!;
      saved = current.copyWith(
        title: _title.text,
        dueAt: _dueAt,
        priority: _priority,
        categoryId: _categoryId,
        estimateMinutes: () => _estimate,
        notes: () => _notes.text,
        repeat: _repeat,
      );
      await repo.updateTask(saved);
    } else {
      saved = await repo.addTask(
        TaskDraft(
          title: _title.text,
          dueAt: _dueAt,
          priority: _priority,
          categoryId: _categoryId,
          estimateMinutes: _estimate,
          notes: _notes.text,
          repeat: _repeat,
        ),
      );
    }
    navigator.pop();

    // If the filters on the page would hide the task just saved, say so: otherwise it looks lost.
    final hidden = !filter.matches(saved, now, categories);
    final verb = _editing ? 'Task updated' : 'Task added';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(hidden ? '$verb — your filters are hiding it' : verb),
          action: hidden ? SnackBarAction(label: 'Show it', onPressed: filters.reset) : null,
        ),
      );
  }

  Future<void> _delete() async {
    final task = widget.task!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${task.title}”?', style: PandaText.title),
        content: const Text('You can undo this straight afterwards.', style: PandaText.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PandaColors.overdue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = ref.read(taskRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.deleteTask(task.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted “${task.title}”'),
          action: SnackBarAction(label: 'Undo', onPressed: () => repo.updateTask(task)),
        ),
      );
  }

  Future<void> _pickDate() async {
    final today = dateOnly(ref.read(clockProvider));
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDay,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365 * 5)),
      helpText: 'When is it due?',
    );
    if (picked != null) setState(() => _dueDay = dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 17, minute: 0),
      helpText: 'What time is it due?',
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _newCategory() async {
    final id = await showDialog<String>(context: context, builder: (_) => const _NewCategoryDialog());
    if (id != null) setState(() => _categoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    final phone = Breakpoints.isPhone(context);
    final now = ref.watch(clockProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];

    final header = Padding(
      padding: EdgeInsets.fromLTRB(24, phone ? 0 : 24, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(_editing ? 'Edit task' : 'New task', style: PandaText.title)),
          if (_editing && phone)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: PandaColors.overdue),
              child: const Text('Delete'),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(backgroundColor: PandaColors.rice, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );

    final fields = <Widget>[
      _Field(
        label: 'What needs doing?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: !_editing,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              style: PandaText.body,
              decoration: InputDecoration(
                hintText: 'E.g. I am quite fat.',
                counterText: '',
                errorText: _showErrors && _title.text.trim().isEmpty ? 'Give your task a short name' : null,
              ),
              onChanged: (_) {
                if (_showErrors) setState(() {});
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: Why do you need a tip its literally adding tasks',
              style: PandaText.caption.copyWith(color: PandaColors.muted),
            ),
          ],
        ),
      ),
      _Field(
        label: 'When is it due?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DueDayOptions(
              today: dateOnly(now),
              selected: _dueDay,
              onSelect: (d) => setState(() => _dueDay = d),
              onPick: _pickDate,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OptionPill(
                  label: _time == null ? 'Add a time' : formatTime(_dueAt),
                  selected: false,
                  icon: Icons.schedule_rounded,
                  onTap: _pickTime,
                  onRemove: _time == null ? null : () => setState(() => _time = null),
                ),
                Text(
                  'Time is optional — defaults to end of day',
                  style: PandaText.caption.copyWith(color: PandaColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
      _Field(
        label: 'How important is it?',
        child: Row(
          children: [
            for (final p in Priority.values) ...[
              Expanded(
                child: _PriorityTile(priority: p, selected: p == _priority, onTap: () => setState(() => _priority = p)),
              ),
              if (p != Priority.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      _Field(
        label: 'Category',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in categories)
              OptionPill(
                label: c.name,
                dotColor: c.color,
                style: OptionPillStyle.ink,
                selected: c.id == _categoryId,
                onTap: () => setState(() => _categoryId = c.id),
              ),
            OptionPill(label: 'New', icon: Icons.add_rounded, selected: false, onTap: _newCategory),
          ],
        ),
      ),
      _Field(
        label: 'How long will it take?',
        hint: '(optional)',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (minutes, label) in const [(15, '15 min'), (30, '30 min'), (60, '1 hour'), (120, '2 hours+')])
              OptionPill(
                label: label,
                selected: _estimate == minutes,
                onTap: () => setState(() => _estimate = _estimate == minutes ? null : minutes),
              ),
          ],
        ),
      ),
      _Field(
        label: 'Notes',
        hint: '(optional)',
        child: TextField(
          controller: _notes,
          minLines: 3,
          maxLines: 6,
          style: PandaText.body,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Add any details, links or reminders…'),
        ),
      ),
      _Field(
        label: 'Repeat',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in Repeat.values)
              OptionPill(
                label: r.label,
                icon: r == Repeat.none ? null : Icons.repeat_rounded,
                selected: r == _repeat,
                onTap: () => setState(() => _repeat = r),
              ),
          ],
        ),
      ),
    ];

    final cancel = OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'));
    final save = FilledButton(onPressed: _saving ? null : _save, child: Text(_editing ? 'Save changes' : 'Save task'));
    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: phone
          ? Row(
              children: [
                Expanded(child: cancel),
                const SizedBox(width: 12),
                Expanded(child: save),
              ],
            )
          : Row(
              children: [
                if (_editing)
                  TextButton.icon(
                    onPressed: _delete,
                    style: TextButton.styleFrom(foregroundColor: PandaColors.overdue),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                cancel,
                const SizedBox(width: 12),
                save,
              ],
            ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (phone ? 0.92 : 0.9)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final f in fields) Padding(padding: const EdgeInsets.only(top: 16), child: f)],
              ),
            ),
          ),
          const Divider(height: 1),
          actions,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, this.hint, required this.child});
  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          text: label,
          style: PandaText.heading,
          children: [
            if (hint != null)
              TextSpan(
                text: '  $hint',
                style: PandaText.caption.copyWith(color: PandaColors.muted),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _DueDayOptions extends StatelessWidget {
  const _DueDayOptions({required this.today, required this.selected, required this.onSelect, required this.onPick});
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final friday = today.add(Duration(days: (DateTime.friday - today.weekday) % 7));
    final nextMonday = today.add(Duration(days: 8 - today.weekday));
    final options = <(String, DateTime)>[
      ('Today', today),
      ('Tomorrow', today.add(const Duration(days: 1))),
      if (friday.isAfter(today.add(const Duration(days: 1))))
        (today.weekday < DateTime.friday ? 'This Fri' : formatShortDate(friday, today), friday),
      ('Next week', nextMonday),
    ];
    final custom = !options.any((o) => isSameDay(o.$2, selected));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, day) in options)
          OptionPill(label: label, selected: isSameDay(day, selected), onTap: () => onSelect(day)),
        OptionPill(
          label: custom ? formatShortDate(selected, today) : 'Pick a date',
          icon: Icons.calendar_month_rounded,
          selected: custom,
          onTap: onPick,
        ),
      ],
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({required this.priority, required this.selected, required this.onTap});
  final Priority priority;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = priority == Priority.urgent;
    final leafColor = urgent ? PandaColors.overdue : PandaColors.bambooDark;
    final textColor = selected ? PandaColors.bambooDark : (urgent ? PandaColors.overdue : PandaColors.ink);
    return Semantics(
      button: true,
      selected: selected,
      label: '${priority.label} priority',
      excludeSemantics: true,
      child: Material(
        color: selected ? PandaColors.bambooTint : PandaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
          side: BorderSide(color: selected ? PandaColors.bambooDark : PandaColors.line, width: selected ? 2 : 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (var i = 0; i < priority.weight; i++) LeafIcon(size: 16, color: leafColor)],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  child: Text(priority.label, style: PandaText.bodyStrong.copyWith(color: textColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewCategoryDialog extends ConsumerStatefulWidget {
  const _NewCategoryDialog();

  @override
  ConsumerState<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends ConsumerState<_NewCategoryDialog> {
  final _name = TextEditingController();
  late Color _color = _firstUnusedColor();
  bool _busy = false;
  String? _error;

  /// New categories start with a colour no existing category uses, so they can be told apart.
  Color _firstUnusedColor() {
    final used = {for (final c in ref.read(categoriesProvider).value ?? const []) c.color};
    final choices = PandaColors.categoryChoices.values;
    return choices.firstWhere((c) => !used.contains(c), orElse: () => choices.first);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return; // a double click (or click plus Enter) must not add two categories
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name');
      return;
    }
    final taken = (ref.read(categoriesProvider).value ?? const []).any(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) {
      setState(() => _error = 'You already have a category called “$name”');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(taskRepositoryProvider).addCategory(name, _color);
      if (mounted) Navigator.of(context).pop(c.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn’t save the category. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New category', style: PandaText.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: 'e.g. Exams', counterText: '', errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 16),
        const Text('Colour', style: PandaText.heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            for (final e in PandaColors.categoryChoices.entries)
              Semantics(
                label: e.key,
                selected: e.value == _color,
                button: true,
                excludeSemantics: true,
                child: Tooltip(
                  message: e.key,
                  excludeFromSemantics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      // The swatch is its own button, so the hover and press highlight is clipped to
                      // the circle instead of spilling into a bigger blob around it.
                      child: Material(
                        color: e.value,
                        shape: CircleBorder(
                          side: BorderSide(
                            color: e.value == _color ? PandaColors.ink : PandaColors.line,
                            width: e.value == _color ? 3 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          hoverColor: PandaColors.ink.withValues(alpha: 0.12),
                          onTap: () => setState(() => _color = e.value),
                          child: const SizedBox.square(dimension: 34),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _add, child: const Text('Add category')),
    ],
  );
}
