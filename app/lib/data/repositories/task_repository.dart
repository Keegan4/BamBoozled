import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:uuid/uuid.dart';

import '../../core/theme/colors.dart';
import '../../domain/models/category.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import '../canvas/canvas_feed.dart';
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

/// What an import from Canvas changed.
class CanvasImportResult {
  const CanvasImportResult({this.added = 0, this.updated = 0, this.removed = 0, this.total = 0});
  final int added;
  final int updated;
  final int removed;

  /// Items in the feed that are now tasks.
  final int total;
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

  Stream<List<Task>> watchTasks() =>
      (db.select(db.tasks)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
          .watch()
          .map((rows) => rows.map(_taskFromRow).toList());

  Stream<List<Category>> watchCategories() =>
      (db.select(db.categories)
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
    final category = Category(id: _newId(), name: name.trim(), color: color, sortOrder: count, updatedAt: _clock());
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
    final updated = task.copyWith(title: task.title.trim(), notes: () => _blankToNull(task.notes), updatedAt: _clock());
    await db.into(db.tasks).insertOnConflictUpdate(_taskToCompanion(updated, dirty: true));
    _changed();
  }

  /// Ticks a task off (or back on). A repeating task's next occurrence is not created here: it
  /// appears the day after, from [spawnNextRepeats].
  Future<void> setDone(String id, bool done) async {
    final task = await getTask(id);
    if (task == null || task.isDone == done) return;
    final now = _clock();
    await db.transaction(() async {
      await db
          .into(db.tasks)
          .insertOnConflictUpdate(
            _taskToCompanion(task.copyWith(completedAt: () => done ? now : null, updatedAt: now), dirty: true),
          );
      if (task.repeat == Repeat.none) return;
      final nextDue = task.repeat.next(task.dueAt);
      final copies =
          await (db.select(db.tasks)..where(
                (t) =>
                    t.title.equals(task.title) &
                    t.dueAt.equals(nextDue) &
                    t.categoryId.equals(task.categoryId) &
                    t.repeat.equals(task.repeat.index) &
                    t.completedAt.isNull(),
              ))
              .get();
      if (done) {
        // Ticking again after an Undo brings back the copy the Undo took away.
        for (final copy in copies.where((c) => c.deletedAt != null)) {
          await (db.update(db.tasks)..where((t) => t.id.equals(copy.id))).write(
            TasksCompanion(deletedAt: const Value(null), updatedAt: Value(now), dirty: const Value(true)),
          );
        }
      } else {
        // Un-ticking takes the next copy away again (if it has appeared by now), so the task is
        // back exactly as it was. A copy the user has since edited (updatedAt moved on) is theirs.
        final untouched = copies.where((c) => c.deletedAt == null && c.createdAt == c.updatedAt).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        for (final copy in untouched.take(1)) {
          await (db.update(db.tasks)..where((t) => t.id.equals(copy.id))).write(
            TasksCompanion(deletedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)),
          );
        }
      }
    });
    _changed();
  }

  /// Creates the next occurrence of every repeating task that was finished before today and has
  /// none yet, so a weekly task finished on Saturday is back on Sunday. Safe to call at any time.
  /// Returns how many were created.
  Future<int> spawnNextRepeats() async {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    var created = 0;
    await db.transaction(() async {
      final finished =
          await (db.select(db.tasks)..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.completedAt.isNotNull() &
                    t.completedAt.isSmallerThanValue(today) &
                    t.repeat.equals(Repeat.none.index).not(),
              ))
              .get();
      for (final row in finished) {
        final task = _taskFromRow(row);
        final nextDue = task.repeat.next(task.dueAt);
        // Deleted copies count too: a next occurrence the user deleted stays deleted.
        final nextId = '${task.id}-next';
        final existing =
            await (db.select(db.tasks)..where(
                  (t) =>
                      t.id.equals(nextId) |
                      (t.title.equals(task.title) &
                          t.dueAt.equals(nextDue) &
                          t.categoryId.equals(task.categoryId) &
                          t.repeat.equals(task.repeat.index)),
                ))
                .get();
        if (existing.isNotEmpty) continue;
        await db
            .into(db.tasks)
            .insert(
              _taskToCompanion(
                Task(
                  // A fixed id, so two devices that both create it end up with one row, not two.
                  id: nextId,
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
                dirty: true,
              ),
            );
        created++;
      }
    });
    if (created > 0) _changed();
    return created;
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
      b.update(
        db.tasks,
        const TasksCompanion(dirty: Value(false)),
        where: (row) => row.id.equals(t.id) & row.updatedAt.equals(t.updatedAt),
      );
    }
  });

  Future<void> markCategoriesClean(List<Category> pushed) => db.batch((b) {
    for (final c in pushed) {
      b.update(
        db.categories,
        const CategoriesCompanion(dirty: Value(false)),
        where: (row) => row.id.equals(c.id) & row.updatedAt.equals(c.updatedAt),
      );
    }
  });

  // ---- Canvas ----

  /// Task id for a Canvas item. Built from Canvas's own id, so the phone and the computer make the
  /// same task when both read the feed, and sync merges them instead of doubling them.
  static String canvasTaskId(String uid) => '${Task.canvasIdPrefix}${uid.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}';

  /// Category id for a course, the same on every device.
  static String canvasCategoryId(String? course) {
    if (course == null) return 'canvas-course';
    final slug = course.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return 'canvas-course-${slug.length > 60 ? slug.substring(0, 60) : slug}';
  }

  /// Brings the tasks in line with the feed:
  /// * new items become tasks, in a category for their course;
  /// * Canvas owns the title, due date and link, so changes there are copied over. The user's own
  ///   priority, category, notes, estimate and tick are never touched;
  /// * an unfinished task whose item has gone from the feed is removed, but only if it falls within
  ///   the dates the feed covers (Canvas leaves old items out of the feed; they are kept);
  /// * a task the user deleted stays deleted, unless [restoreDeleted] (used when connecting again).
  Future<CanvasImportResult> applyCanvasItems(List<CanvasItem> items, {bool restoreDeleted = false}) async {
    final now = _clock();
    var added = 0, updated = 0, removed = 0;
    final byId = <String, CanvasItem>{};
    for (final item in items) {
      byId.putIfAbsent(canvasTaskId(item.uid), () => item);
    }
    await db.transaction(() async {
      final existing = {
        for (final r in await (db.select(db.tasks)..where((t) => t.id.like('${Task.canvasIdPrefix}%'))).get())
          r.id: _taskFromRow(r),
      };
      final categories = {for (final c in await db.select(db.categories).get()) c.id: _categoryFromRow(c)};

      Future<String> categoryFor(String? course) async {
        final id = canvasCategoryId(course);
        final current = categories[id];
        if (current != null && !current.isDeleted) return id;
        if (current != null) {
          final restored = Category(
            id: id,
            name: current.name,
            color: current.color,
            sortOrder: current.sortOrder,
            updatedAt: now,
          );
          await db.into(db.categories).insertOnConflictUpdate(_categoryToCompanion(restored, dirty: true));
          categories[id] = restored;
          return id;
        }
        final used = {for (final c in categories.values.where((c) => !c.isDeleted)) c.color};
        final choices = PandaColors.categoryChoices.values.toList();
        final color = choices.firstWhere(
          (c) => !used.contains(c),
          orElse: () => choices[categories.length % choices.length],
        );
        final name = course ?? 'Canvas';
        final category = Category(
          id: id,
          name: name.length > 40 ? name.substring(0, 40) : name,
          color: color,
          sortOrder: categories.length,
          updatedAt: now,
        );
        await db.into(db.categories).insert(_categoryToCompanion(category, dirty: true));
        categories[id] = category;
        return id;
      }

      for (final MapEntry(key: id, value: item) in byId.entries) {
        final current = existing[id];
        if (current == null) {
          final task = Task(
            id: id,
            title: item.title,
            dueAt: item.dueAt,
            categoryId: await categoryFor(item.course),
            link: item.link,
            createdAt: now,
            updatedAt: now,
          );
          await db.into(db.tasks).insert(_taskToCompanion(task, dirty: true));
          added++;
          continue;
        }
        if (current.isDeleted && !restoreDeleted) continue;
        final changed = current.title != item.title || current.dueAt != item.dueAt || current.link != item.link;
        if (!changed && !current.isDeleted) continue;
        var categoryId = current.categoryId;
        if (current.isDeleted && categories[categoryId]?.isDeleted != false) {
          categoryId = await categoryFor(item.course);
        }
        final next = current.copyWith(
          title: item.title,
          dueAt: item.dueAt,
          link: () => item.link,
          categoryId: categoryId,
          deletedAt: () => null,
          updatedAt: now,
        );
        await db.into(db.tasks).insertOnConflictUpdate(_taskToCompanion(next, dirty: true));
        if (current.isDeleted) {
          added++;
        } else {
          updated++;
        }
      }

      if (byId.isNotEmpty) {
        final windowStart = byId.values.map((i) => i.dueAt).reduce((a, b) => a.isBefore(b) ? a : b);
        for (final t in existing.values) {
          if (byId.containsKey(t.id) || t.isDeleted || t.isDone || t.dueAt.isBefore(windowStart)) continue;
          await db
              .into(db.tasks)
              .insertOnConflictUpdate(_taskToCompanion(t.copyWith(deletedAt: () => now, updatedAt: now), dirty: true));
          removed++;
        }
      }
    });
    if (added + updated + removed > 0) _changed();
    return CanvasImportResult(added: added, updated: updated, removed: removed, total: byId.length);
  }

  /// Removes every task and course category that came from Canvas (when disconnecting).
  Future<int> removeCanvasTasks() async {
    final now = _clock();
    final removed =
        await (db.update(db.tasks)..where((t) => t.id.like('${Task.canvasIdPrefix}%') & t.deletedAt.isNull())).write(
          TasksCompanion(deletedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)),
        );
    await (db.update(db.categories)..where((c) => c.id.like('canvas-course%') & c.deletedAt.isNull())).write(
      CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)),
    );
    _changed();
    return removed;
  }

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
    link: r.link,
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
    link: Value(t.link),
  );

  static Category _categoryFromRow(CategoryRow r) => Category(
    id: r.id,
    name: r.name,
    color: Color(r.colorValue),
    sortOrder: r.sortOrder,
    updatedAt: r.updatedAt,
    deletedAt: r.deletedAt,
  );

  static CategoriesCompanion _categoryToCompanion(Category c, {required bool dirty}) => CategoriesCompanion.insert(
    id: c.id,
    name: c.name,
    colorValue: c.color.toARGB32(),
    sortOrder: Value(c.sortOrder),
    updatedAt: c.updatedAt,
    deletedAt: Value(c.deletedAt),
    dirty: Value(dirty),
  );
}
