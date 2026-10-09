import 'package:bamboozled/data/local/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() => db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)));
  tearDown(() => db.close());

  test('creates the three tables', () async {
    final tables = {
      for (final r in await db.customSelect("select name from sqlite_master where type = 'table'").get())
        r.read<String>('name'),
    };
    expect(tables, containsAll(['tasks', 'categories', 'settings']));
  });

  test('creates indexes for the due-date list and for finding unsynced rows', () async {
    final indexes = {
      for (final r in await db.customSelect("select name from sqlite_master where type = 'index'").get())
        r.read<String>('name'),
    };
    expect(indexes, containsAll(['tasks_due_at', 'tasks_dirty']));
  });

  test('schema version is 1 (bump it, with a migration, when tables change)', () {
    expect(db.schemaVersion, 1);
  });

  group('settings', () {
    test('missing key reads as null', () async {
      expect(await db.getSetting('nothing'), isNull);
    });

    test('values can be replaced and removed', () async {
      await db.setSetting('k', 'one');
      await db.setSetting('k', 'two');
      expect(await db.getSetting('k'), 'two');
      await db.setSetting('k', null);
      expect(await db.getSetting('k'), isNull);
    });

    test('watchSetting emits every change', () async {
      final seen = <String?>[];
      final sub = db.watchSetting('display_name').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.setSetting('display_name', 'Ms Tan');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.setSetting('display_name', 'Mr Lim');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.setSetting('display_name', null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen, [null, 'Ms Tan', 'Mr Lim', null]);
    });
  });

  group('title length is enforced by the table definition', () {
    TasksCompanion row(String title) => TasksCompanion.insert(
      id: 'x',
      title: title,
      dueAt: DateTime(2026, 10, 8),
      priority: 2,
      categoryId: 'general',
      createdAt: DateTime(2026, 10, 8),
      updatedAt: DateTime(2026, 10, 8),
    );

    test('accepts 1 to 200 characters', () async {
      await db.into(db.tasks).insert(row('a'));
      await db.into(db.tasks).insert(row('b' * 200).copyWith(id: const Value('y')));
      expect(await db.tasks.count().getSingle(), 2);
    });

    test('rejects an empty title', () async {
      await expectLater(db.into(db.tasks).insert(row('')), throwsA(isA<InvalidDataException>()));
    });

    test('rejects a title over 200 characters', () async {
      await expectLater(db.into(db.tasks).insert(row('a' * 201)), throwsA(isA<InvalidDataException>()));
    });
  });
}
