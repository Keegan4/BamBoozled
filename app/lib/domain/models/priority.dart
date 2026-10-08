/// How important a task is. The [weight] feeds the "Do next" scorer.
enum Priority {
  low(1, 'Low'),
  medium(2, 'Medium'),
  high(3, 'High'),
  urgent(4, 'Urgent');

  const Priority(this.weight, this.label);

  /// 1 (Low) to 4 (Urgent). Also the number of leaves shown on the badge.
  final int weight;
  final String label;

  static Priority fromWeight(int weight) =>
      Priority.values.firstWhere((p) => p.weight == weight, orElse: () => Priority.medium);
}

enum Repeat {
  none('Never'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const Repeat(this.label);
  final String label;

  /// The next due date after [from] for a repeating task.
  DateTime next(DateTime from) => switch (this) {
    Repeat.none => from,
    Repeat.daily => from.add(const Duration(days: 1)),
    Repeat.weekly => from.add(const Duration(days: 7)),
    Repeat.monthly => _addMonth(from),
  };

  static DateTime _addMonth(DateTime d) {
    final year = d.month == 12 ? d.year + 1 : d.year;
    final month = d.month == 12 ? 1 : d.month + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
  }
}
