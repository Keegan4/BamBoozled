import 'dart:io';

import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:bamboozled/domain/services/priority_scorer.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// The life of a task: created, ticked off, un-ticked, repeated, deleted and synced. These tests exist
/// because tasks appeared to "come and go": every way a task can change is checked here, and that
/// nothing else about it changes with it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TaskRepository repo;
  late DateTime now;
  var seq = 0;

  setUp(() async {
    now = DateTime(2026, 10, 8, 9);
    seq = 0;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    repo = TaskRepository(db, clock: () => now, newId: () => 'id${seq++}');
    await repo.ensureDefaultCategories();
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Future<List<Task>> all() => repo.watchTasks().first;
  Future<Task> stored(String id) async => (await repo.getTask(id))!;
  void later([Duration by = const Duration(minutes: 5)]) => now = now.add(by);

  TaskDraft draft(
    String title, {
    DateTime? due,
    Priority priority = Priority.medium,
    String category = 'general',
    Repeat repeat = Repeat.none,
    int? estimate,
    String? notes,
  }) => TaskDraft(
    title: title,
    dueAt: due ?? DateTime(2026, 10, 9, 17),
    priority: priority,
    categoryId: category,
    repeat: repeat,
    estimateMinutes: estimate,
    notes: notes,
  );

  /// Everything about a task that the user can see or set, so tests can say "nothing else changed".
  List<Object?> face(Task t) => [
    t.id,
    t.title,
    t.dueAt,
    t.priority,
    t.categoryId,
    t.estimateMinutes,
    t.notes,
    t.repeat,
    t.createdAt,
  ];

  group('creating tasks', () {
    test('a task is saved exactly as entered', () async {
      final t = await repo.addTask(
        draft(
          'Plan CCA trip',
          due: DateTime(2026, 10, 15, 9, 30),
          priority: Priority.urgent,
          category: 'cca',
          repeat: Repeat.weekly,
          estimate: 120,
          notes: 'Book the bus',
        ),
      );
      final back = await stored(t.id);
      expect(back.title, 'Plan CCA trip');
      expect(back.dueAt, DateTime(2026, 10, 15, 9, 30));
      expect(back.priority, Priority.urgent);
      expect(back.categoryId, 'cca');
      expect(back.repeat, Repeat.weekly);
      expect(back.estimateMinutes, 120);
      expect(back.notes, 'Book the bus');
      expect(back.isDone, isFalse);
      expect(back.isDeleted, isFalse);
      expect(back.createdAt, now);
      expect(back.updatedAt, now);
    });

    for (final p in Priority.values) {
      test('${p.label} priority is stored and listed', () async {
        final t = await repo.addTask(draft('Priority ${p.label}', priority: p));
        expect((await all()).singleWhere((x) => x.id == t.id).priority, p);
      });
    }

    for (final (id, name, _) in defaultCategories) {
      test('a task in the $name category is stored and listed', () async {
        final t = await repo.addTask(draft('In $name', category: id));
        expect((await all()).singleWhere((x) => x.id == t.id).categoryId, id);
      });
    }

    for (final r in Repeat.values) {
      test('${r.label} repeat is stored and listed', () async {
        final t = await repo.addTask(draft('Repeat ${r.label}', repeat: r));
        expect((await all()).singleWhere((x) => x.id == t.id).repeat, r);
      });
    }

    test('every combination of priority, category and repeat can be created and none is lost', () async {
      final expected = <String, List<Object?>>{};
      for (final p in Priority.values) {
        for (final (cat, _, _) in defaultCategories) {
          for (final r in Repeat.values) {
            final t = await repo.addTask(draft('${p.name}/$cat/${r.name}', priority: p, category: cat, repeat: r));
            expected[t.id] = face(t);
          }
        }
      }
      final listed = await all();
      expect(listed, hasLength(4 * 6 * 4));
      expect({for (final t in listed) t.id: face(t)}, expected);
      expect(listed.map((t) => t.id).toSet(), hasLength(96), reason: 'ids are unique');
    });

    for (final (label, due) in <(String, DateTime)>[
      ('overdue by a year', DateTime(2025, 10, 8, 9)),
      ('due this very minute', DateTime(2026, 10, 8, 9)),
      ('end of today', DateTime(2026, 10, 8, 23, 59)),
      ('midnight tomorrow', DateTime(2026, 10, 9)),
      ('a leap day', DateTime(2028, 2, 29, 12)),
      ('New Year\'s Eve', DateTime(2026, 12, 31, 23, 59)),
      ('five years away', DateTime(2031, 10, 8, 9)),
    ]) {
      test('a task $label keeps its exact due time', () async {
        final t = await repo.addTask(draft('Due $label', due: due));
        expect((await stored(t.id)).dueAt, due);
        expect((await all()).map((x) => x.id), contains(t.id));
      });
    }

    for (final (label, title) in <(String, String)>[
      ('one character', 'x'),
      ('the longest allowed (200)', 'y' * 200),
      ('emoji and accents', 'Café 🐼 naïve 数学'),
      ('quotes and symbols', 'Say "hi" & <b>bye</b> — 50% off'),
      ('extra spaces around', '   padded   '),
    ]) {
      test('a title with $label is saved (spaces trimmed)', () async {
        final t = await repo.addTask(draft(title));
        expect((await stored(t.id)).title, title.trim());
      });
    }

    test('an empty or blank title is refused and nothing is saved', () async {
      await expectLater(repo.addTask(draft('')), throwsA(isA<InvalidDataException>()));
      await expectLater(repo.addTask(draft('    ')), throwsA(isA<InvalidDataException>()));
      await expectLater(repo.addTask(draft('z' * 201)), throwsA(isA<InvalidDataException>()));
      expect(await all(), isEmpty);
    });

    test('notes: blank becomes none, text is kept with newlines and symbols', () async {
      expect((await stored((await repo.addTask(draft('a', notes: '   '))).id)).notes, isNull);
      expect((await stored((await repo.addTask(draft('b', notes: ''))).id)).notes, isNull);
      final long = 'Line one\nLine two — “quoted” 🐼\n${'n' * 5000}';
      expect((await stored((await repo.addTask(draft('c', notes: long))).id)).notes, long);
    });

    test('two identical tasks are two tasks', () async {
      await repo.addTask(draft('Same'));
      await repo.addTask(draft('Same'));
      expect(await all(), hasLength(2));
    });

    test('tasks created at the same moment all appear, in due order', () async {
      await Future.wait([
        repo.addTask(draft('C', due: DateTime(2026, 10, 12))),
        repo.addTask(draft('A', due: DateTime(2026, 10, 9))),
        repo.addTask(draft('B', due: DateTime(2026, 10, 10))),
      ]);
      expect((await all()).map((t) => t.title), ['A', 'B', 'C']);
    });

    test('a new task is dirty, so it will be uploaded', () async {
      final t = await repo.addTask(draft('Upload me'));
      expect((await repo.dirtyTasks()).map((x) => x.id), [t.id]);
    });

    test('the list updates by itself when a task is added', () async {
      final seen = <int>[];
      final sub = repo.watchTasks().listen((l) => seen.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.addTask(draft('One'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.addTask(draft('Two'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(seen, [0, 1, 2]);
    });
  });

  group('marking a task done', () {
    test('records when it was finished and nothing else about the task changes', () async {
      final t = await repo.addTask(
        draft('Mark essays', priority: Priority.high, category: 'teaching', estimate: 60, notes: 'n'),
      );
      later();
      await repo.setDone(t.id, true);
      final done = await stored(t.id);
      expect(done.isDone, isTrue);
      expect(done.completedAt, now);
      expect(done.updatedAt, now);
      expect(face(done), face(t), reason: 'title, due time, priority, category, notes, estimate all unchanged');
      expect(done.isDeleted, isFalse);
    });

    test('a done task is kept, not removed: it is still in the list of tasks', () async {
      final t = await repo.addTask(draft('Keep me'));
      await repo.setDone(t.id, true);
      final listed = await all();
      expect(listed.map((x) => x.id), [t.id]);
      expect(listed.single.isDone, isTrue);
    });

    test('a done task is never overdue, however late', () async {
      final t = await repo.addTask(draft('Late', due: DateTime(2026, 10, 1)));
      expect((await stored(t.id)).isOverdue(now), isTrue);
      await repo.setDone(t.id, true);
      expect((await stored(t.id)).isOverdue(now), isFalse);
    });

    test('it is queued for upload again', () async {
      final t = await repo.addTask(draft('Sync me'));
      await repo.markTasksClean(await repo.dirtyTasks());
      expect(await repo.dirtyTasks(), isEmpty);
      later();
      await repo.setDone(t.id, true);
      expect((await repo.dirtyTasks()).single.isDone, isTrue);
    });

    test('ticking twice (a double click) is harmless: the finish time does not move', () async {
      final t = await repo.addTask(draft('Double'));
      later();
      await repo.setDone(t.id, true);
      final first = (await stored(t.id)).completedAt;
      later(const Duration(hours: 1));
      await repo.setDone(t.id, true);
      expect((await stored(t.id)).completedAt, first);
      expect(await all(), hasLength(1));
    });

    test('ticking at exactly the same moment from two places finishes it once', () async {
      final t = await repo.addTask(draft('Race'));
      await Future.wait([repo.setDone(t.id, true), repo.setDone(t.id, true), repo.setDone(t.id, true)]);
      expect(await all(), hasLength(1));
      expect((await stored(t.id)).isDone, isTrue);
    });

    test('an unknown task id does nothing', () async {
      await repo.setDone('no-such-task', true);
      await repo.setDone('no-such-task', false);
      expect(await all(), isEmpty);
    });

    test('only the ticked task changes; the others are untouched', () async {
      final a = await repo.addTask(draft('A'));
      final b = await repo.addTask(draft('B'));
      final c = await repo.addTask(draft('C'));
      later();
      await repo.setDone(b.id, true);
      expect((await stored(a.id)).isDone, isFalse);
      expect((await stored(b.id)).isDone, isTrue);
      expect((await stored(c.id)).isDone, isFalse);
      expect((await stored(a.id)).updatedAt, a.updatedAt);
    });

    test('a finished task is left out of the Do next ranking', () async {
      final a = await repo.addTask(draft('A', due: DateTime(2026, 10, 8, 12)));
      final b = await repo.addTask(draft('B', due: DateTime(2026, 10, 9, 12)));
      await repo.setDone(a.id, true);
      expect(const PriorityScorer().rank(await all(), now).map((r) => r.task.id), [b.id]);
    });

    test('a task finished while the app was closed is still finished afterwards (survives a reopen)', () async {
      final path = '${Directory.systemTemp.path}/bamboozled_lifecycle_${DateTime.now().microsecondsSinceEpoch}.sqlite';
      final file = File(path);
      var disk = AppDatabase(NativeDatabase(file));
      var diskRepo = TaskRepository(disk, clock: () => now, newId: () => 'disk${seq++}');
      await diskRepo.ensureDefaultCategories();
      final t = await diskRepo.addTask(draft('Persist me', priority: Priority.high));
      later();
      await diskRepo.setDone(t.id, true);
      await diskRepo.dispose();
      await disk.close();

      disk = AppDatabase(NativeDatabase(file));
      diskRepo = TaskRepository(disk, clock: () => now, newId: () => 'x');
      await diskRepo.ensureDefaultCategories();
      final back = (await diskRepo.getTask(t.id))!;
      expect(back.isDone, isTrue);
      expect(back.completedAt, now);
      expect(face(back), face(t));
      expect((await diskRepo.watchTasks().first), hasLength(1));
      await diskRepo.dispose();
      await disk.close();
      file.deleteSync();
    });
  });

  group('un-ticking: tasks come back exactly as they were', () {
    test('the task is not done again and everything else is unchanged', () async {
      final t = await repo.addTask(
        draft(
          'Back again',
          priority: Priority.urgent,
          category: 'cca',
          estimate: 30,
          notes: 'x',
          due: DateTime(2026, 10, 9, 17),
        ),
      );
      later();
      await repo.setDone(t.id, true);
      later();
      await repo.setDone(t.id, false);
      final back = await stored(t.id);
      expect(back.isDone, isFalse);
      expect(back.completedAt, isNull);
      expect(face(back), face(t), reason: 'the same due time, priority, category, notes and estimate');
    });

    test('it goes back to the same place in the Do next order', () async {
      final tasks = <Task>[
        await repo.addTask(draft('Overdue', due: DateTime(2026, 10, 7, 23, 59), priority: Priority.medium)),
        await repo.addTask(draft('Tomorrow high', due: DateTime(2026, 10, 9, 17), priority: Priority.high)),
        await repo.addTask(draft('Today low', due: DateTime(2026, 10, 8, 18), priority: Priority.low)),
        await repo.addTask(draft('Urgent next week', due: DateTime(2026, 10, 15, 9), priority: Priority.urgent)),
        await repo.addTask(draft('Sec 2 quiz', due: DateTime(2026, 10, 12, 23, 59), priority: Priority.high)),
      ];
      const scorer = PriorityScorer();
      List<String> order(List<Task> l) => scorer.rank(l, now).map((r) => r.task.title).toList();
      final before = order(await all());
      expect(before, ['Overdue', 'Tomorrow high', 'Today low', 'Urgent next week', 'Sec 2 quiz']);

      for (final t in tasks) {
        later(const Duration(seconds: 1)); // a new time each cycle: the position must not depend on it
        await repo.setDone(t.id, true);
        expect(order(await all()), isNot(contains(t.title)));
        later(const Duration(seconds: 1));
        await repo.setDone(t.id, false);
        expect(order(await all()), before, reason: 'after un-ticking "${t.title}"');
      }
    });

    test('ticking and un-ticking 25 times in a row leaves one identical task', () async {
      final t = await repo.addTask(draft('Flicker', priority: Priority.high));
      for (var i = 0; i < 25; i++) {
        later(const Duration(seconds: 1));
        await repo.setDone(t.id, true);
        expect((await stored(t.id)).isDone, isTrue, reason: 'cycle $i done');
        later(const Duration(seconds: 1));
        await repo.setDone(t.id, false);
        expect((await stored(t.id)).isDone, isFalse, reason: 'cycle $i undone');
      }
      final listed = await all();
      expect(listed, hasLength(1));
      expect(face(listed.single), face(t));
    });

    test('un-ticking a task that is not done does nothing', () async {
      final t = await repo.addTask(draft('Untouched'));
      await repo.setDone(t.id, false);
      expect(await stored(t.id), t);
    });

    test('un-ticking is queued for upload so other devices get it too', () async {
      final t = await repo.addTask(draft('Sync back'));
      later();
      await repo.setDone(t.id, true);
      await repo.markTasksClean(await repo.dirtyTasks());
      later();
      await repo.setDone(t.id, false);
      final dirty = await repo.dirtyTasks();
      expect(dirty.single.id, t.id);
      expect(dirty.single.isDone, isFalse);
    });

    test('a task that was overdue is overdue again when un-ticked', () async {
      final t = await repo.addTask(draft('Late', due: DateTime(2026, 10, 1)));
      await repo.setDone(t.id, true);
      await repo.setDone(t.id, false);
      expect((await stored(t.id)).isOverdue(now), isTrue);
    });
  });

  group('repeating tasks', () {
    for (final (repeat, next) in <(Repeat, DateTime)>[
      (Repeat.daily, DateTime(2026, 10, 10, 17)),
      (Repeat.weekly, DateTime(2026, 10, 16, 17)),
      (Repeat.monthly, DateTime(2026, 11, 9, 17)),
    ]) {
      test(
        'finishing a ${repeat.label.toLowerCase()} task schedules the next one for ${next.day}/${next.month}',
        () async {
          final t = await repo.addTask(
            draft(
              'Report',
              repeat: repeat,
              priority: Priority.high,
              category: 'admin',
              estimate: 45,
              notes: 'Use template',
            ),
          );
          await repo.setDone(t.id, true);
          final tasks = await all();
          expect(tasks, hasLength(2));
          final copy = tasks.singleWhere((x) => x.id != t.id);
          expect(copy.dueAt, next);
          expect(copy.isDone, isFalse);
          expect(
            [copy.title, copy.priority, copy.categoryId, copy.estimateMinutes, copy.notes, copy.repeat],
            ['Report', Priority.high, 'admin', 45, 'Use template', repeat],
          );
        },
      );
    }

    test('a task that does not repeat never spawns a copy', () async {
      final t = await repo.addTask(draft('One-off'));
      await repo.setDone(t.id, true);
      expect(await all(), hasLength(1));
    });

    test('un-ticking removes the copy again, so there is no duplicate left behind', () async {
      final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
      later();
      await repo.setDone(t.id, true);
      expect(await all(), hasLength(2));
      later();
      await repo.setDone(t.id, false);
      final listed = await all();
      expect(listed, hasLength(1), reason: 'the auto-created copy is taken away');
      expect(listed.single.id, t.id);
      expect(listed.single.isDone, isFalse);
    });

    test('tick, untick, tick again: exactly one next copy, never two', () async {
      final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
      for (var i = 0; i < 6; i++) {
        later();
        await repo.setDone(t.id, true);
        later();
        await repo.setDone(t.id, false);
      }
      later();
      await repo.setDone(t.id, true);
      final listed = await all();
      expect(listed, hasLength(2));
      expect(listed.where((x) => !x.isDone).single.dueAt, DateTime(2026, 10, 16, 17));
    });

    test('a copy the user has edited is theirs: un-ticking leaves it alone', () async {
      final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
      later();
      await repo.setDone(t.id, true);
      final copy = (await all()).singleWhere((x) => x.id != t.id);
      later();
      await repo.updateTask(copy.copyWith(priority: Priority.urgent));
      later();
      await repo.setDone(t.id, false);
      expect((await all()).map((x) => x.id), containsAll([t.id, copy.id]));
    });

    test('a copy that has itself been finished is left alone', () async {
      final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
      await repo.setDone(t.id, true);
      final copy = (await all()).singleWhere((x) => x.id != t.id);
      later();
      await repo.setDone(copy.id, true); // creates a third
      later();
      await repo.setDone(t.id, false);
      final listed = await all();
      expect(listed.where((x) => x.id == copy.id), hasLength(1));
      expect((await stored(copy.id)).isDone, isTrue);
    });

    test('finishing is not blocked when two identical tasks already exist for the next date', () async {
      final t = await repo.addTask(draft('Weekly report', repeat: Repeat.weekly));
      await repo.addTask(draft('Weekly report', due: DateTime(2026, 10, 16, 17)));
      await repo.addTask(draft('Weekly report', due: DateTime(2026, 10, 16, 17)));
      await repo.setDone(t.id, true); // used to throw "too many elements"
      expect((await stored(t.id)).isDone, isTrue);
      expect(await all(), hasLength(3), reason: 'a next one already exists, so none is added');
    });

    test('the chain continues: finishing each copy schedules the next week', () async {
      var current = (await repo.addTask(draft('Weekly', repeat: Repeat.weekly, due: DateTime(2026, 10, 9, 17))));
      final dues = [current.dueAt];
      for (var i = 0; i < 4; i++) {
        await repo.setDone(current.id, true);
        current = (await all()).singleWhere((x) => !x.isDone);
        dues.add(current.dueAt);
      }
      expect(dues, [for (var i = 0; i < 5; i++) DateTime(2026, 10, 9 + 7 * i, 17)]);
    });

    test('a monthly task on the 31st lands on the last day of shorter months', () async {
      final t = await repo.addTask(draft('Month end', repeat: Repeat.monthly, due: DateTime(2026, 1, 31, 12)));
      await repo.setDone(t.id, true);
      expect((await all()).singleWhere((x) => !x.isDone).dueAt, DateTime(2026, 2, 28, 12));
    });
  });

  group('deleting and restoring', () {
    test('a deleted task leaves the list but is kept, marked, so deletion can sync', () async {
      final t = await repo.addTask(draft('Bye'));
      later();
      await repo.deleteTask(t.id);
      expect(await all(), isEmpty);
      final kept = await stored(t.id);
      expect(kept.isDeleted, isTrue);
      expect((await repo.dirtyTasks()).single.id, t.id);
    });

    test('a deleted task that was done stays deleted and done', () async {
      final t = await repo.addTask(draft('Done then deleted'));
      await repo.setDone(t.id, true);
      await repo.deleteTask(t.id);
      expect(await all(), isEmpty);
      expect((await stored(t.id)).isDone, isTrue);
    });

    test('undoing a delete (saving the original again) brings it back unchanged', () async {
      final t = await repo.addTask(draft('Oops', priority: Priority.high, notes: 'keep'));
      await repo.deleteTask(t.id);
      later();
      await repo.updateTask(t);
      final back = (await all()).single;
      expect(face(back), face(t));
      expect(back.isDeleted, isFalse);
    });

    test('a done task can be un-ticked after being restored from delete', () async {
      final t = await repo.addTask(draft('Round trip'));
      await repo.setDone(t.id, true);
      final done = await stored(t.id);
      await repo.deleteTask(t.id);
      later();
      await repo.updateTask(done.copyWith(deletedAt: () => null));
      expect((await all()).single.isDone, isTrue);
      await repo.setDone(t.id, false);
      expect((await all()).single.isDone, isFalse);
    });
  });

  group('editing', () {
    test('changing one thing changes only that, and moves updatedAt', () async {
      final t = await repo.addTask(draft('Old title', priority: Priority.low, category: 'admin'));
      later();
      await repo.updateTask(t.copyWith(title: 'New title'));
      final back = await stored(t.id);
      expect(back.title, 'New title');
      expect(back.priority, Priority.low);
      expect(back.categoryId, 'admin');
      expect(back.updatedAt, now);
      expect(back.createdAt, t.createdAt);
    });

    test('editing a finished task keeps it finished', () async {
      final t = await repo.addTask(draft('Done and edited'));
      await repo.setDone(t.id, true);
      later();
      await repo.updateTask((await stored(t.id)).copyWith(title: 'Renamed'));
      final back = await stored(t.id);
      expect(back.title, 'Renamed');
      expect(back.isDone, isTrue);
    });

    test('moving a task\'s due date changes where it appears, not whether it exists', () async {
      final t = await repo.addTask(draft('Move me', due: DateTime(2026, 10, 9, 17)));
      await repo.updateTask(t.copyWith(dueAt: DateTime(2026, 10, 20, 9)));
      expect((await all()).single.dueAt, DateTime(2026, 10, 20, 9));
    });
  });

  group('two devices', () {
    late FakeServer server;
    late Device phone;
    late Device laptop;

    setUp(() async {
      server = FakeServer();
      phone = Device(server, () => now, 'phone');
      laptop = Device(server, () => now, 'laptop');
      await phone.repo.ensureDefaultCategories();
      await laptop.repo.ensureDefaultCategories();
    });
    tearDown(() async {
      await phone.close();
      await laptop.close();
    });

    Future<void> syncBoth() async {
      await phone.sync.syncNow();
      await laptop.sync.syncNow();
      await phone.sync.syncNow();
    }

    test('ticking on the phone shows as done on the laptop, and un-ticking brings it back', () async {
      final t = await phone.repo.addTask(draft('Shared'));
      await syncBoth();
      later();
      await phone.repo.setDone(t.id, true);
      await syncBoth();
      expect((await laptop.tasks()).single.isDone, isTrue);
      later();
      await laptop.repo.setDone(t.id, false);
      await syncBoth();
      expect((await phone.tasks()).single.isDone, isFalse);
      expect((await laptop.tasks()).single.isDone, isFalse);
      expect(face((await phone.tasks()).single), face(t));
    });

    test('if both change it, the later change wins on both devices, whichever syncs first', () async {
      final t = await phone.repo.addTask(draft('Argument'));
      await syncBoth();

      later();
      await phone.repo.setDone(t.id, true); // 9:05
      later();
      await laptop.repo.setDone(t.id, true); // 9:10 ...
      later();
      await laptop.repo.setDone(t.id, false); // 9:15: the latest word is "not done"

      await laptop.sync.syncNow();
      await phone.sync.syncNow();
      await laptop.sync.syncNow();
      expect((await phone.tasks()).single.isDone, isFalse);
      expect((await laptop.tasks()).single.isDone, isFalse);
    });

    test('an old tick made offline cannot undo a newer un-tick made elsewhere', () async {
      final t = await phone.repo.addTask(draft('Offline'));
      await syncBoth();
      later();
      await phone.repo.setDone(t.id, true); // phone offline: 9:05, not yet uploaded
      later(const Duration(minutes: 30));
      await laptop.repo.updateTask((await laptop.tasks()).single.copyWith(title: 'Edited later on the laptop'));
      await laptop.sync.syncNow();
      await phone.sync.syncNow(); // phone's older tick arrives after the laptop's newer edit
      await laptop.sync.syncNow();
      final onLaptop = (await laptop.tasks()).single;
      expect(onLaptop.title, 'Edited later on the laptop');
      expect((await phone.tasks()).single.title, 'Edited later on the laptop');
      expect(onLaptop.isDone, (await phone.tasks()).single.isDone, reason: 'both devices agree');
    });

    test('a task deleted on one device disappears from the other, and no stray copy reappears', () async {
      final t = await phone.repo.addTask(draft('Delete me'));
      await syncBoth();
      later();
      await laptop.repo.deleteTask(t.id);
      await syncBoth();
      expect(await phone.tasks(), isEmpty);
      await syncBoth();
      expect(await phone.tasks(), isEmpty);
      expect(await laptop.tasks(), isEmpty);
    });

    test('a repeating task finished on both devices at once does not multiply', () async {
      final t = await phone.repo.addTask(draft('Weekly', repeat: Repeat.weekly));
      await syncBoth();
      later();
      await phone.repo.setDone(t.id, true);
      await laptop.repo.setDone(t.id, true);
      await syncBoth();
      await syncBoth();
      final onPhone = await phone.tasks();
      final onLaptop = await laptop.tasks();
      expect(onPhone.length, onLaptop.length, reason: 'devices agree on what exists');
      expect(onPhone.where((x) => !x.isDone && x.dueAt == DateTime(2026, 10, 16, 17)).length, lessThanOrEqualTo(2));
    });
  });
}
