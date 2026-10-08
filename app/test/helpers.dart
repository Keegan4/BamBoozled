import 'package:bamboozled/app.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Thursday 8 October 2026, 9:00 am — the date used in the Figma mockups.
final testNow = DateTime(2026, 10, 8, 9);

class FixedClock extends ClockNotifier {
  @override
  DateTime build() => testNow;
}

class TestApp {
  TestApp._(this.db, this.repo);
  final AppDatabase db;
  final TaskRepository repo;

  static Future<TestApp> create({bool withSampleTasks = true, String? name = 'Ms Tan'}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    var ids = 0;
    final repo = TaskRepository(db, clock: () => testNow, newId: () => 'id${ids++}');
    await repo.ensureDefaultCategories();
    if (name != null) await db.setSetting(displayNameKey, name);
    if (withSampleTasks) await addSampleTasks(repo);
    return TestApp._(db, repo);
  }

  /// Same tasks as the Figma mockup.
  static Future<void> addSampleTasks(TaskRepository repo) async {
    Future<void> add(String title, DateTime due, Priority p, String cat) =>
        repo.addTask(TaskDraft(title: title, dueAt: due, priority: p, categoryId: cat));
    await add('Submit term report', DateTime(2026, 10, 7, 23, 59), Priority.medium, 'admin');
    await add('Mark 3A essays', DateTime(2026, 10, 9, 17), Priority.high, 'teaching');
    await add('Reply to parent emails', DateTime(2026, 10, 8, 18), Priority.low, 'admin');
    await add('Plan CCA trip', DateTime(2026, 10, 15, 9), Priority.urgent, 'cca');
    await add('Prepare Sec 2 quiz', DateTime(2026, 10, 12, 23, 59), Priority.high, 'teaching');
    await add('Staff meeting slides', DateTime(2026, 10, 14, 15), Priority.medium, 'meetings');
    await add('Book dentist', DateTime(2026, 10, 16, 23, 59), Priority.low, 'personal');
    final done = await repo.addTask(
      TaskDraft(
        title: 'Print worksheets',
        dueAt: DateTime(2026, 10, 6, 8),
        priority: Priority.medium,
        categoryId: 'teaching',
      ),
    );
    await repo.setDone(done.id, true);
  }

  Widget widget() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      taskRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWith(FixedClock.new),
      routerProvider.overrideWith((ref) => buildRouter()),
    ],
    child: const BamBoozledApp(),
  );

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget());
    await settle(tester);
  }

  /// Lets drift streams deliver (they run on real async) and the UI settle.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await repo.dispose();
      await db.close();
    });
  }
}
