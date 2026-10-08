import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repo;
  late DateTime now;
  var ids = 0;

  setUp(() {
    now = DateTime(2026, 10, 8, 14);
    ids = 0;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    repo = TaskRepository(db, clock: () => now, newId: () => 'id${ids++}');
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  TaskDraft draft(String title, {Repeat repeat = Repeat.none, DateTime? due}) => TaskDraft(
        title: title,
        dueAt: due ?? DateTime(2026, 10, 9, 17),
        priority: Priority.high,
        categoryId: 'teaching',
        repeat: repeat,
      );

  test('seeds default categories once', () async {
    await repo.ensureDefaultCategories();
    await repo.ensureDefaultCategories();
    final cats = await repo.watchCategories().first;
    expect(cats.map((c) => c.name), ['General', 'Teaching', 'Admin', 'Meetings', 'CCA', 'Personal']);
    expect(await repo.dirtyCategories(), isEmpty, reason: 'seeded rows are not uploaded');
  });

  test('adds, edits and lists tasks; trims title and blank notes', () async {
    final t = await repo.addTask(TaskDraft(
        title: '  Mark 3A essays ', dueAt: DateTime(2026, 10, 9), categoryId: 'teaching', notes: '   '));
    expect(t.title, 'Mark 3A essays');
    expect(t.notes, isNull);
    now = now.add(const Duration(minutes: 5));
    await repo.updateTask(t.copyWith(title: 'Mark 3B essays', priority: Priority.urgent));
    final tasks = await repo.watchTasks().first;
    expect(tasks.single.title, 'Mark 3B essays');
    expect(tasks.single.priority, Priority.urgent);
    expect(tasks.single.updatedAt, now);
  });

  test('soft-deletes tasks so the deletion can sync', () async {
    final t = await repo.addTask(draft('Old task'));
    await repo.deleteTask(t.id);
    expect(await repo.watchTasks().first, isEmpty);
    final dirty = await repo.dirtyTasks();
    expect(dirty.single.deletedAt, now);
  });

  test('completing a repeating task schedules the next one, once', () async {
    final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
    await repo.setDone(t.id, true);
    await repo.setDone(t.id, false);
    await repo.setDone(t.id, true);
    final tasks = await repo.watchTasks().first;
    expect(tasks, hasLength(2));
    expect(tasks.first.isDone, isTrue);
    expect(tasks.last.dueAt, DateTime(2026, 10, 16, 17));
    expect(tasks.last.isDone, isFalse);
  });

  test('markTasksClean keeps rows that changed after the push', () async {
    final a = await repo.addTask(draft('A'));
    await repo.addTask(draft('B'));
    final pushed = await repo.dirtyTasks();
    now = now.add(const Duration(seconds: 1));
    await repo.updateTask(a.copyWith(title: 'A edited'));
    await repo.markTasksClean(pushed);
    expect((await repo.dirtyTasks()).map((t) => t.title), ['A edited']);
  });

  test('applyRemoteTasks: newest updatedAt wins', () async {
    final local = await repo.addTask(draft('Local title'));
    final older = local.copyWith(title: 'Older remote', updatedAt: now.subtract(const Duration(minutes: 1)));
    final newer = local.copyWith(title: 'Newer remote', updatedAt: now.add(const Duration(minutes: 1)));
    final brandNew = Task(
        id: 'remote-1',
        title: 'From phone',
        dueAt: DateTime(2026, 10, 10),
        categoryId: 'admin',
        createdAt: now,
        updatedAt: now);

    expect(await repo.applyRemoteTasks([older, brandNew]), 1);
    expect((await repo.getTask(local.id))!.title, 'Local title');
    expect(await repo.applyRemoteTasks([newer]), 1);
    final stored = (await repo.getTask(local.id))!;
    expect(stored.title, 'Newer remote');
    expect((await repo.dirtyTasks()).map((t) => t.id), isNot(contains(local.id)));
  });

  test('preserves sub-second timestamps', () async {
    now = DateTime(2026, 10, 8, 14, 0, 0, 123);
    final t = await repo.addTask(draft('Precise'));
    expect((await repo.getTask(t.id))!.updatedAt, now);
  });

  test('custom categories get a colour and sort last', () async {
    await repo.ensureDefaultCategories();
    final c = await repo.addCategory(' Exams ', PandaColors.honey);
    final cats = await repo.watchCategories().first;
    expect(cats.last.name, 'Exams');
    expect(cats.last.color, PandaColors.honey);
    expect((await repo.dirtyCategories()).single.id, c.id);
  });

  test('settings round-trip', () async {
    await db.setSetting('display_name', 'Ms Tan');
    expect(await db.getSetting('display_name'), 'Ms Tan');
    await db.setSetting('display_name', null);
    expect(await db.getSetting('display_name'), isNull);
  });
}
