import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:uuid/uuid.dart';

import '../../core/theme/colors.dart';
import '../../domain/models/category.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import '../local/app_database.dart';

/// What the user fills in on the add/edit task form.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.dueAt,
    this.priority = Priority.medium,
    required this.categoryId,
    this.estimateMinutes,
    this.notes,
    this.repeat = Repeat.none,
  });

  final String title;
  final DateTime dueAt;
  final Priority priority;
  final String categoryId;
  final int? estimateMinutes;
  final String? notes;
  final Repeat repeat;
}

/// Categories every new install starts with. Fixed ids so two devices that
/// both seed them don't create duplicates once they sync.
final defaultCategories = [
  ('general', 'General', PandaColors.stone),
  ('teaching', 'Teaching', PandaColors.sky),
  ('admin', 'Admin', PandaColors.honey),
  ('meetings', 'Meetings', PandaColors.blush),
  ('cca', 'CCA', PandaColors.lavender),
  ('personal', 'Personal', PandaColors.mint),
];
const defaultCategoryId = 'general';

/// The single source of truth for tasks and categories. The UI only talks to
/// this repository (and so to the local database); SyncService copies changes
/// to and from Supabase in the background.
class TaskRepository {
  TaskRepository(this.db, {DateTime Function()? clock, String Function()? newId})
      : _clock = clock ?? DateTime.now,
        _newId = newId ?? const Uuid().v4;

  final AppDatabase db;
  final DateTime Function() _clock;
  final String Function() _newId;
  final _localChanges = StreamController<void>.broadcast();

  /// Fires after every local write, so sync can push soon after.
  Stream<void> get localChanges => _localChanges.stream;

  void _changed() => _localChanges.add(null);

  // ---- Reads ----

  Stream<List<Task>> watchTasks() => (db.select(db.tasks)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
      .watch()
      .map((rows) => rows.map(_taskFromRow).toList());

  Stream<List<Category>> watchCategories() => (db.select(db.categories)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]))
      .watch()
      .map((rows) => rows.map(_categoryFromRow).toList());

  Future<Task?> getTask(String id) async {
    final row = await (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _taskFromRow(row);
  }

  // ---- Writes ----

  Future<void> ensureDefaultCategories() async {
    final count = await db.categories.count().getSingle();
    if (count > 0) return;
    // An old timestamp, so any copy already on the server wins.
    final seededAt = DateTime.utc(2000);
    await db.batch((b) {
      for (final (i, (id, name, color)) in defaultCategories.indexed) {
        b.insert(
          db.categories,
          CategoriesCompanion.insert(
            id: id,
            name: name,
            colorValue: color.toARGB32(),
            sortOrder: Value(i),
            updatedAt: seededAt,
            dirty: const Value(false),
          ),
        );
      }
    });
  }

  Future<Category> addCategory(String name, Color color) async {
    final count = await db.categories.count().getSingle();
    final category = Category(
      id: _newId(),
      name: name.trim(),
      color: color,
      sortOrder: count,
      updatedAt: _clock(),
    );
    await db.into(db.categories).insert(_categoryToCompanion(category, dirty: true));
    _changed();
    return category;
  }

  Future<Task> addTask(TaskDraft draft) async {
    final now = _clock();
    final task = Task(
      id: _newId(),
      title: draft.title.trim(),
      dueAt: draft.dueAt,
      priority: draft.priority,
      categoryId: draft.categoryId,
      estimateMinutes: draft.estimateMinutes,
      notes: _blankToNull(draft.notes),
      repeat: draft.repeat,
      createdAt: now,
      updatedAt: now,
    );
    await db.into(db.tasks).insert(_taskToCompanion(task, dirty: true));
    _changed();
    return task;
  }

  Future<void> updateTask(Task task) async {
    final updated = task.copyWith(
      title: task.title.trim(),
      notes: () => _blankToNull(task.notes),
      updatedAt: _clock(),
    );
    await db.into(db.tasks).insertOnConflictUpdate(_taskToCompanion(updated, dirty: true));
    _changed();
  }

  /// Ticks a task off (or back on). Finishing a repeating task schedules the next one.
  Future<void> setDone(String id, bool done) async {
    final task = await getTask(id);
    if (task == null || task.isDone == done) return;
    final now = _clock();
    await db.transaction(() async {
      await db.into(db.tasks).insertOnConflictUpdate(_taskToCompanion(
          task.copyWith(completedAt: () => done ? now : null, updatedAt: now),
          dirty: true));
      if (done && task.repeat != Repeat.none) {
        final nextDue = task.repeat.next(task.dueAt);
        final exists = await (db.select(db.tasks)
              ..where((t) => t.title.equals(task.title) & t.dueAt.equals(nextDue) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (exists == null) {
          await db.into(db.tasks).insert(_taskToCompanion(
              Task(
                id: _newId(),
                title: task.title,
                dueAt: nextDue,
                priority: task.priority,
                categoryId: task.categoryId,
                estimateMinutes: task.estimateMinutes,
                notes: task.notes,
                repeat: task.repeat,
                createdAt: now,
                updatedAt: now,
              ),
              dirty: true));
        }
      }
    });
    _changed();
  }

  Future<void> deleteTask(String id) async {
    final now = _clock();
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)),
    );
    _changed();
  }

  // ---- Sync support ----

  Future<List<Task>> dirtyTasks() async =>
      (await (db.select(db.tasks)..where((t) => t.dirty)).get()).map(_taskFromRow).toList();

  Future<List<Category>> dirtyCategories() async =>
      (await (db.select(db.categories)..where((c) => c.dirty)).get()).map(_categoryFromRow).toList();

  /// Clears the dirty flag on rows that haven't changed again since they were pushed.
  Future<void> markTasksClean(List<Task> pushed) => db.batch((b) {
        for (final t in pushed) {
          b.update(db.tasks, const TasksCompanion(dirty: Value(false)),
              where: (row) => row.id.equals(t.id) & row.updatedAt.equals(t.updatedAt));
        }
      });

  Future<void> markCategoriesClean(List<Category> pushed) => db.batch((b) {
        for (final c in pushed) {
          b.update(db.categories, const CategoriesCompanion(dirty: Value(false)),
              where: (row) => row.id.equals(c.id) & row.updatedAt.equals(c.updatedAt));
        }
      });

  /// Applies rows pulled from the server. The newest `updatedAt` wins; a local
  /// row that is newer (and not yet pushed) is kept. Returns rows applied.
  Future<int> applyRemoteTasks(List<Task> remote) async {
    var applied = 0;
    await db.transaction(() async {
      for (final r in remote) {
        final local = await (db.select(db.tasks)..where((t) => t.id.equals(r.id))).getSingleOrNull();
        if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
          await db.into(db.tasks).insertOnConflictUpdate(_taskToCompanion(r, dirty: false));
          applied++;
        }
      }
    });
    return applied;
  }

  Future<int> applyRemoteCategories(List<Category> remote) async {
    var applied = 0;
    await db.transaction(() async {
      for (final r in remote) {
        final local = await (db.select(db.categories)..where((c) => c.id.equals(r.id))).getSingleOrNull();
        if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
          await db.into(db.categories).insertOnConflictUpdate(_categoryToCompanion(r, dirty: false));
          applied++;
        }
      }
    });
    return applied;
  }

  /// Marks everything for upload, e.g. after signing in on a device that was used offline.
  Future<void> markAllDirty() async {
    await db.update(db.tasks).write(const TasksCompanion(dirty: Value(true)));
    await db.update(db.categories).write(const CategoriesCompanion(dirty: Value(true)));
    _changed();
  }

  Future<void> dispose() => _localChanges.close();

  // ---- Mapping ----

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  static Task _taskFromRow(TaskRow r) => Task(
        id: r.id,
        title: r.title,
        dueAt: r.dueAt,
        priority: Priority.fromWeight(r.priority),
        categoryId: r.categoryId,
        estimateMinutes: r.estimateMinutes,
        notes: r.notes,
        repeat: Repeat.values[r.repeat.clamp(0, Repeat.values.length - 1)],
        completedAt: r.completedAt,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
      );

  static TasksCompanion _taskToCompanion(Task t, {required bool dirty}) => TasksCompanion.insert(
        id: t.id,
        title: t.title,
        dueAt: t.dueAt,
        priority: t.priority.weight,
        categoryId: t.categoryId,
        estimateMinutes: Value(t.estimateMinutes),
        notes: Value(t.notes),
        repeat: Value(t.repeat.index),
        completedAt: Value(t.completedAt),
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: Value(t.deletedAt),
        dirty: Value(dirty),
      );

  static Category _categoryFromRow(CategoryRow r) => Category(
        id: r.id,
        name: r.name,
        color: Color(r.colorValue),
        sortOrder: r.sortOrder,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
      );

  static CategoriesCompanion _categoryToCompanion(Category c, {required bool dirty}) =>
      CategoriesCompanion.insert(
        id: c.id,
        name: c.name,
        colorValue: c.color.toARGB32(),
        sortOrder: Value(c.sortOrder),
        updatedAt: c.updatedAt,
        deletedAt: Value(c.deletedAt),
        dirty: Value(dirty),
      );
}
