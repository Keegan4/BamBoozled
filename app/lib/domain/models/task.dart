import 'priority.dart';

/// A single to-do item. See docs/task-format.md for the recommended format.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.dueAt,
    this.priority = Priority.medium,
    required this.categoryId,
    this.estimateMinutes,
    this.notes,
    this.repeat = Repeat.none,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final DateTime dueAt;
  final Priority priority;
  final String categoryId;
  final int? estimateMinutes;
  final String? notes;
  final Repeat repeat;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete marker, so deletions sync to other devices.
  final DateTime? deletedAt;

  bool get isDone => completedAt != null;
  bool get isDeleted => deletedAt != null;
  bool isOverdue(DateTime now) => !isDone && dueAt.isBefore(now);

  Task copyWith({
    String? title,
    DateTime? dueAt,
    Priority? priority,
    String? categoryId,
    int? Function()? estimateMinutes,
    String? Function()? notes,
    Repeat? repeat,
    DateTime? Function()? completedAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        dueAt: dueAt ?? this.dueAt,
        priority: priority ?? this.priority,
        categoryId: categoryId ?? this.categoryId,
        estimateMinutes: estimateMinutes != null ? estimateMinutes() : this.estimateMinutes,
        notes: notes != null ? notes() : this.notes,
        repeat: repeat ?? this.repeat,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.dueAt == dueAt &&
      other.priority == priority &&
      other.categoryId == categoryId &&
      other.estimateMinutes == estimateMinutes &&
      other.notes == notes &&
      other.repeat == repeat &&
      other.completedAt == completedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, dueAt, priority, categoryId, estimateMinutes, notes, repeat,
      completedAt, createdAt, updatedAt, deletedAt);

  @override
  String toString() => 'Task($title, due $dueAt, ${priority.label})';
}
